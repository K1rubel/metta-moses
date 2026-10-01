;; Load contin-nonlinear after the shared reducer and CTK builder.
;;   Arguments: none; reads degree, recursion-depth, operator, and node-cap
;;   settings from global optimizer parameters. Returns the config record.
(= (configuredNonlinearConfig)
   (mkNonlinearConfig (param continPolyDegree) (param continScaffoldDepth)
     (param continOperators) (param continMaxScaffoldNodes)))
;;   $tree: source expression; $context: continuous scoring context;
;;   $step/$expansion/$depth: continuous-knob decoding settings;
;;   $config: nonlinear scaffold bounds/operators. Returns built representation or error.
(= (buildNonlinearRepresentation $tree $context $step $expansion $depth $config)
   (case (continPrepareContext $context)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkContinData $labels $columns $targets)
       (if (== (continCtxSearchMode $context) nonlinear)
           (case (continNonlinearCanonize $tree $labels $config)
             (((mkCEvalError $failure) (mkCEvalError $failure))
              ($scaffold (buildContinRepresentation $scaffold $step $expansion $depth))))
           (mkCEvalError "UnsupportedContinuousSearchMode"))))))
;;   $tree: source expression; $context: continuous scoring context.
;;   Returns a representation using configured knob and nonlinear settings.
(= (configuredNonlinearRepresentation $tree $context)
   (buildNonlinearRepresentation $tree $context
     (param continStep) (param continExpansion) (param continDepth) (configuredNonlinearConfig)))
