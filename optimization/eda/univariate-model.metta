;; Independent univariate EDA model: each schema coordinate gets its own
;; smoothed categorical distribution, with no learned cross-coordinate links.
;; Sampling proceeds in schema order so continuous activation gates can force
;; descendants inactive; those inactive values are canonicalized to zero.
;; Step 9: new implementation, independent of optimization/univariate/.
;; Import field-schema, optimizer-runtime and legal-instance-sampling first.
;; Model rows contain positive categorical WEIGHTS, normalized per coordinate.
;; Only active child observations contribute; tournament multiplicity is kept.
;; Computes smoothed categorical weights by counting observations for each category.
;;   $values: List of observed integer category values for a coordinate.
;;   $card: Total cardinality (number of categories).
;;   $alpha: Dirichlet pseudocount smoothing parameter.
;;   $index: Current category index counter.
;;   Returns: List of positive category weights with pseudocounts added.
(= (edaCategoryWeights $values $card $alpha $index)
   (if (== $index $card) ()
       (cons (+ $alpha (List.length (filter-atom $values $v (== $v $index))))
             (edaCategoryWeights $values $card $alpha (+ $index 1)))))

;; Fits independent categorical distributions for each field from active observation views.
;;   $fields: List of schema field specifications.
;;   $views: List of candidate model views.
;;   $alpha: Smoothing pseudocount.
;;   Returns: List of category weight lists, one per field.
(= (edaFitFields $fields $views $alpha)
   (case $fields
     ((() ())
      ((cons $field $rest)
       (let* (($index (fieldIndex $field))
              ($observations (map-atom $views $view (List.getByIdx $view $index)))
              ($active (filter-atom $observations $observation
                         (case $observation (((mkActiveField $i $value) True) ($inactive False)))))
              ($values (map-atom $active (mkActiveField $i $value) $value)))
         (cons (edaCategoryWeights $values (fieldCardinality $field) $alpha 0)
               (edaFitFields $rest $views $alpha)))))))

;; Fits an independent univariate categorical model across all schema coordinates.
;;   $schema: Field schema of the problem representation.
;;   $selected: Selected population candidate rows.
;;   $alpha: Dirichlet pseudocount.
;;   Returns: mkUnivariateModel holding per-field categorical sampling weights.
(= (edaFitUnivariate $schema $selected $alpha)
   (mkUnivariateModel (edaFitFields (schemaFields $schema)
     (map-atom $selected $row (instanceModelView $schema (candidateInstance $row))) $alpha)))

;; Strict half-open intervals: a zero-weight category never captures draw zero.
;; Callers supply a nonempty positive model and 0 <= draw < sum(weights).
;; Performs roulette-wheel draw over a list of positive category weights.
;;   $weights: List of positive category weights.
;;   $draw: Random threshold scaled between 0 and sum of weights.
;;   $index: Current category index.
;;   Returns: Selected category index.
(= (edaChooseWeight $weights $draw $index)
   (case $weights
     (((cons $weight ()) $index)
      ((cons $weight $rest)
       (if (< $draw $weight) $index
           (edaChooseWeight $rest (- $draw $weight) (+ $index 1)))))))

;; Sequentially samples field values, respecting continuous activation gates.
;;   $fields: Remaining schema field specifications.
;;   $weights: Remaining field weight distributions.
;;   $active: Boolean activation status for current coordinate.
;;   $rng: Random number generator state.
;;   Returns: Tuple ($values $nextRng) containing sampled coordinate values.
(= (edaSampleFields $fields $weights $active $rng)
   (case $fields
     ((() (() $rng))
      ((cons $field $rest)
       (let* (($now (if (== (fieldOffset $field) 0) True $active))
              (($value $next)
                (if $now
                    (let* ((($unit $drawRng) (optimizerRandomUnit $rng))
                           ($total (foldl-atom (car-atom $weights) 0.0 $sum $w (+ $sum $w))))
                      ((edaChooseWeight (car-atom $weights) (* $unit $total) 0) $drawRng))
                    (0 $rng)))
              (($tail $end) (edaSampleFields $rest (cdr-atom $weights)
                              (and $now (not (== $value 0))) $next)))
         ((cons $value $tail) $end))))))

;; Samples a complete legal candidate instance from a fitted univariate model.
;;   $schema: Representation field schema.
;;   (mkUnivariateModel $weights): Fitted univariate model.
;;   $rng: Random number generator state.
;;   Returns: mkLegalSample containing canonical instance and updated RNG state.
(= (edaSampleUnivariate $schema (mkUnivariateModel $weights) $rng)
   (let ($values $next) (edaSampleFields (schemaFields $schema) $weights True $rng)
     (mkLegalSample (mkInst $values) $next)))
