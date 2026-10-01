;; Sample in a topological order of learned + mandatory activation edges.
;; The partial model view uses -1 for inactive parents; genotype output uses 0.
;; Recursively samples coordinates in topological order using local CPTs and Dirichlet priors.
;;   $fields: List of schema field descriptors.
;;   $nodes: Learned BOA local model nodes.
;;   $order: Topological order of coordinate indices.
;;   $alpha: Smoothing pseudocount.
;;   $values: Accumulated raw genotype values (inactive = 0).
;;   $view: Accumulated model view values (inactive = -1).
;;   $rng: Random number generator state.
;;   Returns: mkLegalSample containing the complete candidate instance and updated RNG state.
(= (boaSampleOrder $fields $nodes $order $alpha $values $view $rng)
   (case $order
     ((() (mkLegalSample (mkInst $values) $rng))
      ((cons $index $rest)
       (let* (($field (List.getByIdx $fields $index))
              ($active (all (map-atom (fieldActivationParents $field) $p (> (List.getByIdx $values $p) 0))))
              ($node (List.getByIdx $nodes $index))
              (($value $next) (if $active
                (let* (($context (map-atom (boaNodeParents $node) $p (List.getByIdx $view $p)))
                       ($weights (boaConditionalWeights $node $context $alpha))
                       (($unit $end) (optimizerRandomUnit $rng)))
                  ((edaChooseWeight $weights (* $unit (List.sum $weights)) 0) $end)) (0 $rng))))
         (boaSampleOrder $fields $nodes $rest $alpha (List.replaceAt $values $index $value)
           (List.replaceAt $view $index (if $active $value -1)) $next))))))

;; Samples a novel candidate instance from a fitted BOA model.
;;   $schema: Representation field schema.
;;   (mkBOAModel $nodes $order $alpha $stats): Fitted BOA model.
;;   $rng: Random number generator state.
;;   Returns: mkLegalSample with a canonical instance and updated RNG state.
(= (boaSample $schema (mkBOAModel $nodes $order $alpha $stats) $rng)
   (boaSampleOrder (schemaFields $schema) $nodes $order $alpha
     (fieldDefaults (schemaFields $schema)) (List.repeat (List.length $nodes) -1) $rng))

;; Callback adapting boaFit to the EDA engine interface using active runtime configuration.
;;   $schema: Problem field schema.
;;   $selected: Selected population individuals.
;;   $alpha: Dirichlet pseudocount.
;;   $deadline: Cutoff timestamp.
;;   Returns: Fitted mkBOAModel.
(= (boaFitConfigured $schema $selected $alpha $deadline)
   (boaFit $schema $selected $alpha (boaConfigured) $deadline))

;; Validates system parameters and returns the configured boaOptimizer entry point.
;;   Returns: boaOptimizer function reference, or halts execution if parameters are invalid.
(= (configuredBOAOptimizer)
   (if (all ((edaConfigValid (edaConfigured)) (boaConfigValid (boaConfigured)) (edaReplacementValid))) 
      boaOptimizer
      (let $_message (println! (OptimizerError "Invalid BOA/EDA configuration" (boaConfigured) (edaConfigured)))
       (callPredicate (Predicate (halt 1))))))

;; Main six-argument optimizer entry point for BOA under the MOSES optimizer contract.
;;   $deme: Input population deme containing representation and scored candidates.
;;   $context: Problem scoring context (continuous, Boolean, or action).
;;   $initial: Seed instance.
;;   $limits: Computational and evaluation budgets.
;;   $rng: Random number generator state.
;;   $config: Optimizer configuration arguments.
;;   Returns: mkOptimizerResult containing optimized deme, best instance, and diagnostic stats.
(= (boaOptimizer $deme $context $initial $limits $rng $config)
   (if (not (boaConfigValid (boaConfigured))) (Error (boaConfigured) "Invalid BOA configuration")
     (let* (((mkDeme $rep $rows $id) $deme) (($ctx $target) (edaContext $context))
            ($schema (edaSchema $rep $ctx)))
       (if (not (fieldSchemaValid $schema)) (Error $schema "Invalid BOA schema")
         (if (any (map-atom (schemaFields $schema) $f (> (fieldCardinality $f) (param boaMaxTableCells))))
           (Error $schema "BOA table limit is smaller than a root distribution")
           (edaStart $deme $context $initial $limits $rng (edaConfigured) boaFitConfigured boaSample))))))
