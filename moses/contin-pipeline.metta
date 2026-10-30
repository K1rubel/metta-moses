;; Shared affine/nonlinear lifecycle. Load after optimizer/deme modules.
;; Continuous dispatch is explicit; no Boolean representation/reducer is used.
;; continRequire: $value is a successful result or mkCEvalError. Returns the
;; successful value; errors are printed and halt the run.

(= (continRequire $value)
   (case $value
     (
        ((mkCEvalError $reason) (let $_message (println! (ContinuousError $reason)) (callPredicate (Predicate (halt 1)))))
        ($ok $ok)
      )
  )
)

;; validateContinRun: $context is the continuous run context. Returns True when
;; context, nonlinear settings (when applicable), continuous spec, and run
;; limits are valid; otherwise returns a descriptive mkCEvalError.

(= (validateContinRun $context)
   (case (continPrepareContext $context)
     (
      ((mkCEvalError $reason) (mkCEvalError $reason))
      ($data
       (if (if (== (continCtxSearchMode $context) nonlinear)
                   (not
                      (nonlinearConfigValid (configuredNonlinearConfig))) 
                  False)
           (mkCEvalError "InvalidNonlinearConfig")
           (if (not (continSpecValid (mkContinSpec 0.0 (param continStep) (param continExpansion) (param continDepth))))
               (mkCEvalError "InvalidContinSpec")
               (if (not (continFiniteNumber (param continImprovementThreshold)))
                   (mkCEvalError "InvalidContinuousImprovementThreshold")
                   (if (and (optimizerLimitsValid (configuredOptimizerLimits (param maxEvals)))
                            (and (continNatural (param maxGen))
                                 (and (continNatural (param nDeme)) (continInteger (param seed)))))
                       True (mkCEvalError "InvalidContinuousRunLimits")))))))))

;; configuredAffineRepresentation: 
;;      $tree is an affine exemplar and 
;;      $context supplies data/mode. 
;;      Returns its representation using configured trit settings, or the builder's error.

(= (configuredAffineRepresentation $tree $context)
   (buildAffineRepresentation $tree $context
     (param continStep) (param continExpansion) (param continDepth)))

;; configuredContinRepresentation: 
;;      $tree is an exemplar and 
;;      $context selects linear or nonlinear search. 
;;      Returns the matching representation or error.

(= (configuredContinRepresentation $tree $context)
   (if (== (continCtxSearchMode $context) linear)
       (configuredAffineRepresentation $tree $context)
       (configuredNonlinearRepresentation $tree $context)))

;; createContinDemes: $ids are deme identifiers, $tree the starting exemplar,
;; and $context the run context. Returns an empty mkDeme per identifier, each
;; with the configured continuous representation.

(= (createContinDemes $ids $tree $context)
   (case $ids
     ((() ())
      ((cons $id $rest)
       (let $rep (continRequire (configuredContinRepresentation $tree $context))
         (cons (mkDeme $rep (mkSInstSet ()) $id)
               (createContinDemes $rest $tree $context)))))))

;; Phenotype deduplication before merge, not Boolean getCandidate/treeSpace.
;; continUniqueRows: $rep decodes instances in $rows; $seen contains decoded
;; trees already accepted and $limit caps output size. Returns the first rows
;; with unique phenotypes, up to the limit.

(= (continUniqueRows $rep $rows $seen $limit)
   (if (<= $limit 0) ()
       (case $rows
         ((() ())
          ((cons $row $rest)
           (let $tree (continRequire (finalizeContinCandidate $rep (getInst $row)))
             (if (continContains $tree $seen)
                 (continUniqueRows $rep $rest $seen $limit)
                 (cons $row (continUniqueRows $rep $rest (cons $tree $seen) (- $limit 1))))))))))
;; keepTopContinCandidates: $rep is the continuous representation and the
;; instance set contains scored rows. Returns phenotype-unique rows capped by
;; nEval and maxCandPerDeme.

(= (keepTopContinCandidates $rep (mkSInstSet $rows))
   (let* (($limit (min (param nEval) (List.length $rows)))
          ($capped (if (< (param maxCandPerDeme) 0) $limit (min $limit (param maxCandPerDeme)))))
     (continUniqueRows $rep $rows () $capped)))
;; continMergeBehavior: $context is the scoring context and $tree a candidate
;; phenotype. Returns its cached continuous behavior, or halts on evaluation error.

(= (continMergeBehavior $context $tree)
   (continRequire (cachedContinBehavior $context $tree)))

;; Re-evaluate supplied seed trees in the new run context. Attached seed scores
;; are not trusted across runs/tables. Zero allowance returns an empty archive;
;; no synthetic finite worst score may compete with arbitrary negative SSE.
;; continSeedTreeDecoder: $tree is a supplied seed phenotype; $id and $instance
;; identify the candidate, and $context is the current run context. Returns the
;; reduced seed tree for the shared candidate evaluator.

(= (continSeedTreeDecoder $tree $id $instance $context) (reduceContinTree $tree))

;; continInitializeSeeds: $seeds are supplied exemplars, $context is the new
;; evaluation context, and $left is the remaining evaluation allowance. Returns
;; (merged valid seed population, actual evaluations used).

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

;; initializeContinRun: $context configures data/scoring and $supplied is the
;; optional seed exemplar list. Returns (initialized population, evaluations
;; used), validating settings and evaluating seeds in this run's context.

(= (initializeContinRun $context $supplied)
   (let* (($_valid (continRequire (validateContinRun $context)))
          ($seeds (if (== $supplied ())
                      ((mkExemplar (mkTree (mkNode 0.0) ()) (mkDemeId "seed") () ())) $supplied))
          (($population $used) (continInitializeSeeds $seeds $context (param maxEvals)))
          ($_diag (if (param diagnostics)
                      (println! (ContinuousInitialization (actualEvaluations $used) (retainedSeeds (List.length $population)))) ())))
     ($population $used)))

;; CLI examples: C++ simple symbolic regression order two is x + x*x.
;; srDemoTable: no arguments. Returns a small nonlinear x/y reference table
;; used when SR has no table configured.

(= (srDemoTable) (mkITable ((-2.0 -1.0 0.0 1.0 2.0) (2.0 0.0 0.0 2.0 6.0)) (x y)))

;; linearDemoTable: no arguments. Returns a small y=2*x+1 reference table.

(= (linearDemoTable) (mkITable ((-2.0 -1.0 0.0 1.0 2.0) (-3.0 -1.0 1.0 3.0 5.0)) (x y)))

;; resolveContinTable: reads inputFile or continTable, falling back to the
;; linear demo table. Returns an mkITable or a structured CSV/config error.

(= (resolveContinTable)
   (if (== (param inputFile) "")
       (if (== (param continTable) ()) (linearDemoTable) (param continTable))
       (if (not (== (param continTable) ()))
           (mkCEvalError "BothContinuousCSVAndInMemoryTableConfigured")
           (parse (py-call (csv_helper.load_continuous_table_result (param inputFile) (param targetFeature)))))))

;; linearProblemContext: no arguments; reads CLI settings and the table.
;; Returns (linear context, empty seed list, raw target score), or halts when
;; the table, search mode, or run settings are invalid.

(= (linearProblemContext)
       (let* (($table (continRequire (resolveContinTable)))
              ($target (if (== (param bestScore) ()) 0.0 (param bestScore)))
              ($context (mkContinCtx $table (param continErrorType) (param continComplexityRatio)
                         (param continSearchMode) $target))
              ($_mode (continRequire (if (== (param continSearchMode) linear) True
                                        (mkCEvalError "LinearProblemRequiresLinearMode"))))
              ($_valid (continRequire (validateContinRun $context))))
         ($context () $target)))

;; srProblemContext: no arguments; reads CLI settings and the configured SR
;; table (or demo table). Returns (nonlinear context, empty seed list, target
;; score), or halts on invalid configuration.

(= (srProblemContext)
   (let* (($table (continRequire
                    (if (and (== (param inputFile) "") (== (param continTable) ()))
                        (srDemoTable) (resolveContinTable))))
          ($target (if (== (param bestScore) ()) 0.0 (param bestScore)))
          ($context (mkContinCtx $table (param continErrorType) (param continComplexityRatio) nonlinear $target))
          ($_valid (continRequire (validateContinRun $context))))
     ($context () $target)))
