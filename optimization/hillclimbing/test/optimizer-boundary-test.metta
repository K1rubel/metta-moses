!(import! &self ../../../utilities/general-helpers)
!(import! &self ../../../parameters/registry)
!(import! &self ../../../parameters/defaults)
!(import! &self ../../../utilities/list-methods)
!(import! &self ../../../utilities/nodeId)
!(import! &self ../../../utilities/map)
!(import! &self ../../../utilities/ordered-multimap)
!(import! &self ../../../utilities/lazy-random-selector)
!(import! &self ../../../utilities/pair) 
!(import! &self ../../../reduct/boolean-reduct/rte-helpers)
!(import! &self ../../../reduct/boolean-reduct/cut-unnecessary-or)
!(import! &self ../../../reduct/boolean-reduct/cut-unnecessary-and)
!(import! &self ../../../reduct/boolean-reduct/n-ary-propagate-not)
!(import! &self ../../../reduct/boolean-reduct/n-ary-gather-junctors)
!(import! &self ../../../reduct/boolean-reduct/delete-inconsistent-handle)
!(import! &self ../../../reduct/boolean-reduct/zero-constraint-subsumption)
!(import! &self ../../../reduct/boolean-reduct/one-constraint-subsumption)
!(import! &self ../../../reduct/boolean-reduct/promote-common-constraints)
!(import! &self ../../../reduct/boolean-reduct/reduce-to-elegance)
!(import! &self ../../../utilities/tree)

!(import! &self ../../../scoring/action-registry)
!(import! &self ../../../representation/knob-representation)
!(import! &self ../../../representation/lsk)
!(import! &self ../../../representation/logical-probe) 
!(import! &self ../../../representation/logical-canonize)
!(import! &self ../../../representation/sample-logical-perms)
!(import! &self ../../../representation/add-logical-knobs)
!(import! &self ../../../representation/build-logical)
!(import! &self ../../../representation/build-knobs)
!(import! &self ../../../representation/knob-mapper)
!(import! &self ../../../feature-selection/feature-selection-helpers)
!(import! &self ../../../representation/representation)
!(import! &self ../../../representation/create-representation)





!(import! &self ../../../scoring/cacheSpace)

!(import! &self ../../../examples/tic-tac-toe/tic-tac-toe-helpers)
!(import! &self ../../../examples/tic-tac-toe/random-player)
!(import! &self ../../../examples/tic-tac-toe/minimax-player)
!(import! &self ../../../examples/tic-tac-toe/moves)

!(import! &self ../../../scoring/fitness)
!(import! &self ../../../scoring/boolean-ops)
!(import! &self ../../../scoring/bscore)
!(import! &self ../../../scoring/cscore)
!(import! &self ../../../scoring/action-score)
!(import! &self ../../../scoring/complexity-based-scorer)

!(import! &self ../../../deme/deme-id-creation)
!(import! &self ../../../deme/create-deme)
!(import! &self ../../../deme/score-deme)
!(import! &self ../../../representation/instance)
!(import! &self ../../../optimization/optimizer-contract)
!(import! &self ../../../scoring/candidate-evaluation)
!(import! &self ../../../optimization/optimizer-runtime)
!(import! &self ../crossover-helpers)
!(import! &self ../crossover)
!(import! &self ../../../deme/expand-deme)

!(import! &self ../hill-climbing-helpers)

!(import! &self ../../../moses/neighborhood-sampling)

;; Tiny real Boolean representation: two three-way knobs.
(= (boundaryKnob) (mkLSK (mkDiscKnob (mkMultip 3) (mkDiscSpec 0) (mkDiscSpec 0) ())))
(= (boundaryRep)
   (mkRep (mkKbMap (mkDscMp (((mkDiscSpec 3) (boundaryKnob)) ((mkDiscSpec 3) (boundaryKnob)))))
     (mkTree (mkNode AND)
       ((mkKnob (mkNullVex ((mkTree (mkNode A) ()))) (boundaryKnob) 0)
        (mkKnob (mkNullVex ((mkTree (mkNode B) ()))) (boundaryKnob) 1)))))
(= (boundaryTable) (mkITable ((False True False True) (False False True True) (False False False True)) (A B O)))
(= (boundaryContext) (mkOptimizerContext (mkTruthTableBScore 2 4 (boundaryTable)) 1))
(= (boundaryDeme) (mkDeme (boundaryRep) (mkSInstSet ()) (mkDemeId "boundary")))
(= (boundaryRun $limits $rng)
   (optimizeDeme (boundaryDeme) (boundaryContext) (mkInst (0 0)) $limits $rng (mkOptimizerConfig hc)))
(= (boundarySummary $result)
   ((resultActualEvaluations $result) (resultStopReason $result)
    (diagProposals (resultDiagnostics $result))))
!(set-param diagnostics False)
!(assertEqual (optimizerLimitsValid (mkOptimizerLimits 0 -1 2 0.01)) True)
!(assertEqual (optimizerLimitsValid (mkOptimizerLimits -2 0 0 0)) False)
!(assertEqual (optimizerLimitsValid (mkOptimizerLimits 1 0.5 0 0)) False)
!(assertEqual (optimizerLimitsValid (mkOptimizerLimits 1 1 1 -0.1)) False)
!(assertEqual (optimizerRngNext 1) 48271)
!(assertEqual (optimizerRngNext 48271) 182605794)
!(assertEqual (optimizerRngFromSeed 0) 1)
!(assertEqual (optimizerRngValid (optimizerRngFromSeed -1)) True)
!(assertEqual (optimizerRngValid 0) False)
!(assertEqual
  (case (optimizeDeme (boundaryDeme) (boundaryContext) (mkInst (0 0))
          (mkOptimizerLimits 1 1 1 -1) 1 (mkOptimizerConfig unimplementedOptimizer))
    (((Error $value $reason) True) ($other False))) True)

!(resetCandidateScoreCache)
!(change-state! &zeroResult (boundaryRun (mkOptimizerLimits 0 10 10 -1) 123))
!(assertEqual (boundarySummary (get-state &zeroResult)) (0 stopBudgetExhausted 0))
!(assertEqual (resultBestInstance (get-state &zeroResult)) ())
!(assertEqual (resultNextRngState (get-state &zeroResult)) 123)
!(assertEqual (boundarySummary (boundaryRun (mkOptimizerLimits 10 0 10 -1) 123)) (0 stopProposalsExhausted 0))
!(assertEqual (boundarySummary (boundaryRun (mkOptimizerLimits 10 10 0 -1) 123)) (0 stopGenerationsExhausted 0))
!(assertEqual (boundarySummary (boundaryRun (mkOptimizerLimits 10 10 10 0) 123)) (0 stopTimeExhausted 0))

!(resetCandidateScoreCache)
!(change-state! &oneResult (boundaryRun (mkOptimizerLimits 1 10 10 -1) 123))
!(assertEqual (boundarySummary (get-state &oneResult)) (1 stopBudgetExhausted 1))
!(assertEqual (resultBestInstance (get-state &oneResult)) (mkInst (0 0)))
!(assertEqual (get-state &hcActive) False)
!(assertEqual (get-state &localEvalLimit) -1)
!(assertEqual (get-state &hcProposals) 0)

!(resetCandidateScoreCache)
!(assertEqual (boundarySummary (boundaryRun (mkOptimizerLimits 10 1 10 -1) 123)) (1 stopProposalsExhausted 1))
!(resetCandidateScoreCache)
!(assertEqual (boundarySummary (boundaryRun (mkOptimizerLimits 10 10 1 -1) 123)) (1 stopGenerationsExhausted 1))

;; A narrow proposal allowance forces seeded sampling rather than enumeration.
!(resetCandidateScoreCache)
!(change-state! &sample1 (boundaryRun (mkOptimizerLimits 10 3 10 -1) 123))
!(assertEqual (diagProposals (resultDiagnostics (get-state &sample1))) 3)
!(assertEqual (resultStopReason (get-state &sample1)) stopProposalsExhausted)
!(assertEqual (<= (resultActualEvaluations (get-state &sample1)) 3) True)
!(resetCandidateScoreCache)
!(py-call (random.seed 991))
!(py-call (random.random))
!(change-state! &sample2 (boundaryRun (mkOptimizerLimits 10 3 10 -1) 123))
!(assertEqual (get-state &sample1) (get-state &sample2))
!(assertEqual (not (== (resultNextRngState (get-state &sample1)) 123)) True)

;; Preserve raw and penalized champions, and prefer a valid score below the
;; sentinel over an invalid row. Attached rows require no scorer invocation.
(= (attachedDeme)
   (mkDeme (boundaryRep)
     (mkSInstSet
       ((mkEvaluatedCandidate (mkInst (1 1)) (mkTree (mkNode A) ()) (mkCscore 0 2 10 0 -10) candidateValid)
        (mkEvaluatedCandidate (mkInst (1 0)) (mkTree (mkNode B) ()) (mkCscore -1 1 0 0 -1) candidateValid)
        (mkEvaluatedCandidate (mkInst (0 0)) () (worstCscore) (candidateInvalid "fixture"))))
     (mkDemeId "attached")))
!(change-state! &champions
   (optimizeDeme (attachedDeme) (mkTruthTableBScore 2 4 (boundaryTable)) (mkInst (1 0))
     (mkOptimizerLimits 0 0 0 -1) 456 (mkOptimizerConfig hc)))
!(assertEqual (resultStopReason (get-state &champions)) stopTargetReached)
!(assertEqual (resultBestInstance (get-state &champions)) (mkInst (1 0)))
!(assertEqual (bestRawDeme (resultDeme (get-state &champions))) 0)
!(assertEqual (resultActualEvaluations (get-state &champions)) 0)
!(assertEqual (resultNextRngState (get-state &champions)) 456)

;; An invalid context produces an explicit boundary error AFTER restoring all
;; scope cells, including a pre-existing legacy caller's local limit.
!(change-state! &localEvalLimit 7)
!(assertEqual
  (case (optimizeDeme (boundaryDeme) unsupportedContext (mkInst (0 0))
          (mkOptimizerLimits 10 10 10 -1) 1 (mkOptimizerConfig hc))
    (((Error $value $reason) True) ($other False))) True)
!(assertEqual (get-state &localEvalLimit) 7)
!(assertEqual (get-state &hcActive) False)
!(change-state! &localEvalLimit -1)
!(assertEqual
  (case (boundaryRun (mkOptimizerLimits 1 0.5 1 -1) 1)
    (((Error $value $reason) True) ($other False))) True)
!(assertEqual
  (case (boundaryRun (mkOptimizerLimits 1 1 1 -1) 0)
    (((Error $value $reason) True) ($other False))) True)

!(change-state! &belowSentinel
   (optimizeDeme
     (mkDeme (boundaryRep)
       (mkSInstSet
         ((mkEvaluatedCandidate (mkInst (0 0)) () (worstCscore) (candidateInvalid "bad"))
          (mkEvaluatedCandidate (mkInst (1 1)) (mkTree (mkNode A) ())
             (mkCscore -1e101 1 0 0 -1e101) candidateValid))) (mkDemeId "low"))
     (boundaryContext) (mkInst (1 1)) (mkOptimizerLimits 0 0 0 -1) 1 (mkOptimizerConfig hc)))
!(assertEqual (resultBestInstance (get-state &belowSentinel)) (mkInst (1 1)))
!(assertEqual (resultStopReason (get-state &belowSentinel)) stopBudgetExhausted)

;; Exact ties keep the latest candidate, matching legacy HC, independent of RNG.
!(assertEqual
  (getInst (optimizerBestRow
    ((mkSInst (mkPair (mkInst (1)) (mkCscore -1 1 0 0 -1)))
     (mkSInst (mkPair (mkInst (2)) (mkCscore -1 1 0 0 -1)))))) (mkInst (2)))

;; Several genotypes with one phenotype: initialization costs one scorer call,
;; all four distance-one neighbors are cache hits, and proposals still run out.
(= (constantDeme)
   (mkDeme
     (mkRep (mkKbMap (mkDscMp (((mkDiscSpec 3) (boundaryKnob)) ((mkDiscSpec 3) (boundaryKnob)))))
       (mkTree (mkNode AND) ((mkTree (mkNode A) ()) (mkTree (mkNode B) ()))))
     (mkSInstSet ()) (mkDemeId "constant")))
!(resetCandidateScoreCache)
!(change-state! &duplicates
   (optimizeDeme (constantDeme) (boundaryContext) (mkInst (0 0))
     (mkOptimizerLimits 10 5 10 -1) 77 (mkOptimizerConfig hc)))
!(assertEqual (boundarySummary (get-state &duplicates)) (1 stopProposalsExhausted 5))
!(assertEqual (diagCacheHits (resultDiagnostics (get-state &duplicates))) 4)

!(resetCandidateScoreCache)
!(let (mkDeme $rep $rows $id) (constantDeme)
   (cacheCandidateEvaluation ((boundaryTable) 2)
     (materializeCandidateForContext $rep $id (mkInst (0 0)) ((boundaryTable) 2))
     (mkCandidateScore (worstCscore) (candidateInvalid "cached failure"))))
!(change-state! &allInvalid
   (optimizeDeme (constantDeme) (boundaryContext) (mkInst (0 0))
     (mkOptimizerLimits 10 10 10 -1) 77 (mkOptimizerConfig hc)))
!(assertEqual (boundarySummary (get-state &allInvalid)) (0 stopAllInvalid 1))
!(assertEqual (diagInvalids (resultDiagnostics (get-state &allInvalid))) 1)
!(assertEqual (resultBestInstance (get-state &allInvalid)) ())
!(assertEqual
  (boundarySummary
    (optimizeDeme
      (mkDeme (boundaryRep)
        (mkSInstSet ((mkEvaluatedCandidate (mkInst (0 0)) () (worstCscore) (candidateInvalid "supplied failure"))))
        (mkDemeId "invalid-input"))
      (boundaryContext) (mkInst (0 0)) (mkOptimizerLimits 10 10 10 -1) 1 (mkOptimizerConfig hc)))
  (0 stopAllInvalid 0))

;; The outer budget allocator needs no knowledge of HC: a different algorithm
;; returns the same record and passes its next RNG state to the following deme.
!(bind! &observedShares (new-state ()))
(= (boundaryStub $deme $context $initial $limits $rng $config)
   (let* (($limit (limitsMaxEvals $limits))
          ($_seen (change-state! &observedShares
                     (List.concat (get-state &observedShares) (($limit $rng)))))
          ($calls (if (< $limit 0) 2 $limit)))
     (mkOptimizerResult $deme () $calls stopBudgetExhausted (mkOptimizerDiag 0 0 0 0) (+ $rng 1))))
!(change-state! &optimizerRunRng 101)
!(assertEqual
  (let ($demes $used) (expandDemesCounted ((boundaryDeme) (boundaryDeme) (boundaryDeme))
                       (boundaryContext) boundaryStub 5)
    ((List.length $demes) $used)) (3 5))
!(assertEqual (get-state &observedShares) ((2 101) (2 102) (1 103)))
!(assertEqual (get-state &optimizerRunRng) 104)
!(change-state! &observedShares ())
!(assertEqual
  (let ($demes $used) (expandDemesCounted ((boundaryDeme) (boundaryDeme) (boundaryDeme))
                       (boundaryContext) boundaryStub 1)
    ((List.length $demes) $used)) (1 1))
!(assertEqual (get-state &observedShares) ((1 104)))
!(change-state! &observedShares ())
!(assertEqual
  (let ($demes $used) (expandDemesCounted ((boundaryDeme) (boundaryDeme))
                       (boundaryContext) boundaryStub -1)
    ((List.length $demes) $used)) (2 4))
!(assertEqual (get-state &observedShares) ((-1 105) (-1 106)))
!(assertEqual (expandDemesCounted ((boundaryDeme)) (boundaryContext) boundaryStub 0) (() 0))

;; Real common-contract Boolean search reaches its raw target, even when the
;; complexity-penalized score is negative.
!(resetCandidateScoreCache)
!(change-state! &solvedBoolean
   (optimizeDeme (boundaryDeme) (mkTruthTableBScore 2 4 (boundaryTable)) (mkInst (0 0))
     (mkOptimizerLimits 50 100 20 -1) 1 (mkOptimizerConfig hc)))
!(assertEqual (resultStopReason (get-state &solvedBoolean)) stopTargetReached)
!(assertEqual (bestRawDeme (resultDeme (get-state &solvedBoolean))) 0)
!(assertEqual (<= (resultActualEvaluations (get-state &solvedBoolean)) 50) True)

;; Pure phenotype duplicates can terminate by stagnation with allowance left.
!(set-param hcCrossover False)
!(resetCandidateScoreCache)
!(change-state! &stalled
   (optimizeDeme (constantDeme) (boundaryContext) (mkInst (0 0))
     (mkOptimizerLimits 50 100 20 -1) 1 (mkOptimizerConfig hc)))
!(assertEqual (resultStopReason (get-state &stalled)) stopStagnation)
!(assertEqual (resultActualEvaluations (get-state &stalled)) 1)
!(set-param hcCrossover True)

;; Crossover counts offspring BEFORE deduplication and shares the same proposal
;; cap. A two-offspring allowance must not round each simplex share upward.
!(resetCandidateScoreCache)
!(change-state! &crossLimited
   (optimizeDeme (constantDeme) (boundaryContext) (mkInst (0 0))
     (mkOptimizerLimits 50 7 20 -1) 1 (mkOptimizerConfig hc)))
!(assertEqual (diagProposals (resultDiagnostics (get-state &crossLimited))) 7)
!(assertEqual (resultStopReason (get-state &crossLimited)) stopProposalsExhausted)
!(assertEqual (resultActualEvaluations (get-state &crossLimited)) 1)

!(resetCandidateScoreCache)
!(change-state! &crossFull
   (optimizeDeme (constantDeme) (boundaryContext) (mkInst (0 0))
     (mkOptimizerLimits 50 100 20 -1) 1 (mkOptimizerConfig hc)))
!(assertEqual (resultStopReason (get-state &crossFull)) stopExhaustedSpace)
!(assertEqual (resultActualEvaluations (get-state &crossFull)) 1)

!(resetCandidateScoreCache)
!(change-state! &exhausted
   (optimizeDeme
     (mkDeme (mkRep (mkKbMap (mkDscMp ()))
               (mkTree (mkNode AND) ((mkTree (mkNode A) ()) (mkTree (mkNode B) ()))))
       (mkSInstSet ()) (mkDemeId "empty-fields"))
     (boundaryContext) (mkInst ()) (mkOptimizerLimits -1 10 10 -1) 1 (mkOptimizerConfig hc)))
!(assertEqual (resultStopReason (get-state &exhausted)) stopExhaustedSpace)
;; Repeated attached rows do not prove that every distinct vector was explored.
!(assertEqual
  (hcStopForDeme
    (mkDeme (boundaryRep)
      (mkSInstSet (List.repeat 9 (mkSInst (mkPair (mkInst (0 0)) (mkCscore 0 0 0 0 0)))))
      (mkDemeId "repeated")) 1 0) ())

(= (boundaryActionFitness $tree $episode) 1.0)
!(set-param fitness boundaryActionFitness)
!(resetCandidateScoreCache)
!(change-state! &solvedAction
   (optimizeDeme
     (mkDeme (mkRep (mkKbMap (mkDscMp ()))
               (mkTree (mkNode and_seq) ((mkTree (mkNode boundaryAction) ()))))
       (mkSInstSet ()) (mkDemeId "action"))
     (mkActionCtx 2 0 2) (mkInst ()) (mkOptimizerLimits 1 1 1 -1) 1 (mkOptimizerConfig hc)))
!(assertEqual (boundarySummary (get-state &solvedAction)) (1 stopTargetReached 1))
!(assertEqual (bestRawDeme (resultDeme (get-state &solvedAction))) 2.0)
