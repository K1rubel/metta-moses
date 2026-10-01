;; Shared affine/nonlinear lifecycle. Load after optimizer/deme modules.
;; Continuous dispatch is explicit; no Boolean representation/reducer is used.
(= (continRequire $value)
   (case $value
     (((mkCEvalError $reason)
       (let $_message (println! (ContinuousError $reason))
         (callPredicate (Predicate (halt 1)))))
      ($ok $ok))))

(= (validateContinRun $context)
   (case (continPrepareContext $context)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ($data
       (if (if (== (continCtxSearchMode $context) nonlinear)
               (not (let $valid nonlinearConfigValid
                      (let $config configuredNonlinearConfig ($valid ($config))))) False)
           (mkCEvalError "InvalidNonlinearConfig")
           (if (not (continSpecValid (mkContinSpec 0.0 (param continStep) (param continExpansion) (param continDepth))))
               (mkCEvalError "InvalidContinSpec")
               (if (not (continFiniteNumber (param continImprovementThreshold)))
                   (mkCEvalError "InvalidContinuousImprovementThreshold")
                   (if (and (optimizerLimitsValid (configuredOptimizerLimits (param maxEvals)))
                            (and (continNatural (param maxGen))
                                 (and (continNatural (param nDeme)) (continInteger (param seed)))))
                       True (mkCEvalError "InvalidContinuousRunLimits")))))))))

(= (configuredAffineRepresentation $tree $context)
   (buildAffineRepresentation $tree $context
     (param continStep) (param continExpansion) (param continDepth)))
(= (configuredContinRepresentation $tree $context)
   (if (== (continCtxSearchMode $context) linear)
       (configuredAffineRepresentation $tree $context)
       (let $build configuredNonlinearRepresentation ($build $tree $context))))
(= (createContinDemes $ids $tree $context)
   (case $ids
     ((() ())
      ((cons $id $rest)
       (let $rep (continRequire (configuredContinRepresentation $tree $context))
         (cons (mkDeme $rep (mkSInstSet ()) $id)
               (createContinDemes $rest $tree $context)))))))

;; Phenotype deduplication before merge, not Boolean getCandidate/treeSpace.
(= (continUniqueRows $rep $rows $seen $limit)
   (if (<= $limit 0) ()
       (case $rows
         ((() ())
          ((cons $row $rest)
           (let $tree (continRequire (finalizeContinCandidate $rep (getInst $row)))
             (if (continContains $tree $seen)
                 (continUniqueRows $rep $rest $seen $limit)
                 (cons $row (continUniqueRows $rep $rest (cons $tree $seen) (- $limit 1))))))))))
(= (keepTopContinCandidates $rep (mkSInstSet $rows))
   (let* (($limit (min (param nEval) (List.length $rows)))
          ($capped (if (< (param maxCandPerDeme) 0) $limit (min $limit (param maxCandPerDeme)))))
     (continUniqueRows $rep $rows () $capped)))
(= (continMergeBehavior $context $tree)
   (continRequire (cachedContinBehavior $context $tree)))

;; Re-evaluate supplied seed trees in the new run context. Attached seed scores
;; are not trusted across runs/tables. Zero allowance returns an empty archive;
;; no synthetic finite worst score may compete with arbitrary negative SSE.
(= (continSeedTreeDecoder $tree $id $instance $context) (reduceContinTree $tree))
(= (continInitializeSeeds $seeds $context $left)
   (if (== $left 0) (() 0)
       (case $seeds
         ((() (() 0))
          ((cons (mkExemplar $tree $id $oldScore $oldBehavior) $rest)
           (let* (($rep (continRequire (configuredContinRepresentation $tree $context)))
                  ($seed (finalizeContinCandidate $rep (schemaDefaultInstance (continFieldSchema $rep))))
                  ($batch (evaluateCandidateBatchWith
                    ((mkEvaluatedCandidate (mkInst ()) () () candidatePending))
                    $seed $id $context $left continSeedTreeDecoder scoreMaterializedCandidate))
                  ($used (batchActualEvaluations $batch))
                  (($tail $tailUsed) (continInitializeSeeds $rest $context (optimizerRemaining $left $used)))
                  ($valid (filter-atom (batchEvaluated $batch) $row (candidateIsValid $row)))
                  ($head (map-atom $valid $row
                    (mkExemplar (candidateTree $row) $id (candidateScore $row)
                      (continMergeBehavior $context (candidateTree $row))))))
             ((mergeCandidates $head $tail) (+ $used $tailUsed))))))))
(= (initializeContinRun $context $supplied)
   (let* (($_valid (continRequire (validateContinRun $context)))
          ($seeds (if (== $supplied ())
                      ((mkExemplar (mkTree (mkNode 0.0) ()) (mkDemeId "seed") () ())) $supplied))
          (($population $used) (continInitializeSeeds $seeds $context (param maxEvals)))
          ($_diag (if (param diagnostics)
                      (println! (ContinuousInitialization (actualEvaluations $used) (retainedSeeds (List.length $population)))) ())))
     ($population $used)))

;; CLI examples: C++ simple symbolic regression order two is x + x*x.
(= (srDemoTable) (mkITable ((-2.0 -1.0 0.0 1.0 2.0) (2.0 0.0 0.0 2.0 6.0)) (x y)))
(= (linearDemoTable) (mkITable ((-2.0 -1.0 0.0 1.0 2.0) (-3.0 -1.0 1.0 3.0 5.0)) (x y)))
(= (resolveContinTable)
   (if (== (param inputFile) "")
       (if (== (param continTable) ()) (linearDemoTable) (param continTable))
       (if (not (== (param continTable) ()))
           (mkCEvalError "BothContinuousCSVAndInMemoryTableConfigured")
           (parse (py-call (csv_helper.load_continuous_table_result (param inputFile) (param targetFeature)))))))
(= (linearProblemContext)
       (let* (($table (continRequire (resolveContinTable)))
              ($target (if (== (param bestScore) ()) 0.0 (param bestScore)))
              ($context (mkContinCtx $table (param continErrorType) (param continComplexityRatio)
                         (param continSearchMode) $target))
              ($_mode (continRequire (if (== (param continSearchMode) linear) True
                                        (mkCEvalError "LinearProblemRequiresLinearMode"))))
              ($_valid (continRequire (validateContinRun $context))))
         ($context () $target)))
(= (srProblemContext)
   (let* (($table (continRequire
                    (if (and (== (param inputFile) "") (== (param continTable) ()))
                        (srDemoTable) (resolveContinTable))))
          ($target (if (== (param bestScore) ()) 0.0 (param bestScore)))
          ($context (mkContinCtx $table (param continErrorType) (param continComplexityRatio) nonlinear $target))
          ($_valid (continRequire (validateContinRun $context))))
     ($context () $target)))
