;; Public affine builder, connected to selected-deme/CLI routing by
;; moses/contin-pipeline. Do not overload Boolean construction implicitly.
;; Load contin-canonize and contin-representation before this module.
;;   $exemplar: source expression; $context: prepared continuous scoring
;;   context; $step/$expansion/$depth: knob decoding parameters.
;;   Returns an affine continuous representation or a structured error.
(= (buildAffineRepresentation $exemplar $context $step $expansion $depth)
   (case (continPrepareContext $context)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkContinData $labels $columns $targets)
       (if (== (continCtxSearchMode $context) linear)
           (case (continAffineCanonize $exemplar $labels)
             (((mkCEvalError $failure) (mkCEvalError $failure))
              ($scaffold (buildContinRepresentation $scaffold $step $expansion $depth))))
           (mkCEvalError "UnsupportedContinuousSearchMode"))))))
;;   $exemplar: source expression; $context: continuous scoring context.
;;   Returns an affine representation using step=1, expansion=2, depth=5.
(= (defaultAffineRepresentation $exemplar $context)
   (buildAffineRepresentation $exemplar $context 1.0 2.0 5))
;;   $context: continuous context supplying the input-label vocabulary and mode.
;;   Returns a zero-coefficient affine seed or an unsupported-mode error.
(= (affineSeedFromContext $context)
   (case (continPrepareContext $context)
     (((mkCEvalError $reason) (mkCEvalError $reason))
      ((mkContinData $labels $columns $targets)
       (if (== (continCtxSearchMode $context) linear) (continAffineSeed $labels)
           (mkCEvalError "UnsupportedContinuousSearchMode"))))))
