;; Public six-argument adapter for the independent categorical EDA.
;; The caller still uses the common optimizer contract; configuration is read
;; from optimizer parameters, while edaStart owns initialization, evaluation,
;; budgets, termination, and generation management. The legacy
;; optimization/univariate/ implementation is deliberately untouched.

;; Validates EDA parameters and returns the configured univariate optimizer entry point.
;;   Returns: univariateOptimizer function reference, or halts execution if parameters are invalid.
(= (configuredUnivariateOptimizer)
   (if (and (edaConfigValid (edaConfigured)) (edaReplacementValid)) univariateOptimizer
       (let $_message (println! (OptimizerError "Invalid EDA configuration" (edaConfigured)))
         (callPredicate (Predicate (halt 1))))))

;; Public six-argument optimizer contract entry point for the independent univariate EDA.
;;   $deme: Input population deme containing representation and scored candidates.
;;   $context: Problem scoring context (continuous, Boolean, or action).
;;   $initial: Seed instance.
;;   $limits: Computational and evaluation budgets.
;;   $rng: Random number generator state.
;;   $config: Optimizer configuration arguments.
;;   Returns: mkOptimizerResult containing optimized deme, best instance, and diagnostic stats.
(= (univariateOptimizer $deme $context $initial $limits $rng $config)
   (edaStart $deme $context $initial $limits $rng (edaConfigured)
     edaFitUnivariate edaSampleUnivariate))
