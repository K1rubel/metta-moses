;; Conditional sampling follows the combined learned/activation DAG.
;; Recursively samples coordinates in topological order using local decision trees.
;;   $fields: List of schema field descriptors.
;;   $nodes: Learned hBOA local model nodes.
;;   $order: Topological order of coordinate indices.
;;   $alpha: Smoothing pseudocount.
;;   $values: Accumulated raw genotype values (inactive = 0).
;;   $view: Accumulated model view values (inactive = -1).
;;   $rng: Random number generator state.
;;   Returns: mkLegalSample containing the complete candidate instance and updated RNG state.
(= (hboaSampleOrder $fields $nodes $order $alpha $values $view $rng)
   (case $order
     ((() (mkLegalSample (mkInst $values) $rng))
      ((cons $index $rest)
       (let* (($field (List.getByIdx $fields $index))
              ($active (all (map-atom (fieldActivationParents $field) $p (> (List.getByIdx $values $p) 0))))
              (($value $next) (if $active
                (let* (($weights (hboaWeights (hboaTree (List.getByIdx $nodes $index)) $view $alpha))
                       (($unit $end) (optimizerRandomUnit $rng)))
                  ((edaChooseWeight $weights (* $unit (List.sum $weights)) 0) $end)) (0 $rng))))
         (hboaSampleOrder $fields $nodes $rest $alpha (List.replaceAt $values $index $value)
           (List.replaceAt $view $index (if $active $value -1)) $next))))))

;; Samples a novel candidate instance from a fitted hBOA model.
;;   $schema: Representation field schema.
;;   (mkHBOAModel $nodes $order $alpha $stats): Fitted hBOA model.
;;   $rng: Random number generator state.
;;   Returns: mkLegalSample with a canonical instance and updated RNG state.
(= (hboaSample $schema (mkHBOAModel $nodes $order $alpha $stats) $rng)
   (hboaSampleOrder (schemaFields $schema) $nodes $order $alpha
     (fieldDefaults (schemaFields $schema)) (List.repeat (List.length $nodes) -1) $rng))

;; Callback adapting hboaFit to the EDA engine interface using active runtime configuration.
;;   $schema: Problem field schema.
;;   $selected: Selected population individuals.
;;   $alpha: Dirichlet pseudocount.
;;   $deadline: Cutoff timestamp.
;;   Returns: Fitted mkHBOAModel.
(= (hboaFitConfigured $schema $selected $alpha $deadline)
   (hboaFit $schema $selected $alpha (hboaConfigured) $deadline))

;; Validates system parameters and returns the configured hboaOptimizer entry point.
;;   Returns: hboaOptimizer function reference, or halts execution if parameters are invalid.
(= (configuredHBOAOptimizer)
   (if (all ((edaConfigValid (edaConfigured)) (hboaConfigValid (hboaConfigured)) (edaReplacementValid))) hboaOptimizer
     (let $_message (println! (OptimizerError "Invalid hBOA/EDA configuration" (hboaConfigured) (edaConfigured)))
       (callPredicate (Predicate (halt 1))))))

;; Main six-argument optimizer entry point for hBOA under the MOSES optimizer contract.
;;   $deme: Input population deme containing representation and scored candidates.
;;   $context: Problem scoring context (continuous, Boolean, or action).
;;   $initial: Seed instance.
;;   $limits: Computational and evaluation budgets.
;;   $rng: Random number generator state.
;;   $config: Optimizer configuration arguments.
;;   Returns: mkOptimizerResult containing optimized deme, best instance, and diagnostic stats.
(= (hboaOptimizer $deme $context $initial $limits $rng $config)
   (if (not (hboaConfigValid (hboaConfigured))) 
        (Error (hboaConfigured) "Invalid hBOA configuration")
        (edaStart $deme $context $initial $limits $rng (edaConfigured) hboaFitConfigured hboaSample)))
